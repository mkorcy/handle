require File.expand_path('../../spec_helper',__FILE__)

on_cruby do
  def parse_batch(command)
    (cmd, fname, redirect) = command.split(/\s+/,3)
    File.read(fname).split(/\n\n/).collect { |batch| 
      (op, data) = batch.split(/\n/,2)
      { :op => op.strip, :data => data.strip }
    }
  end

  describe Handle::Command::Connection do
    describe "#initialize" do
      it "file-based private key" do
        Handle::Command::Connection.new('0.NA/FAKE.ADMIN', 300, 'privkey', 'keypass').batch { |b|
          b.should_receive(:`) do |command|
            expect(parse_batch(command)[0]).to eq({ op: "AUTHENTICATE PUBKEY:300:0.NA/FAKE.ADMIN", data: "privkey|keypass" })
            ""
          end
        }.should be_true
      end

      it "shared secret" do
        Handle::Command::Connection.new('0.NA/FAKE.ADMIN', 301, 'seckey') { |b|
          b.should_receive(:`) do |command|
            expect(parse_batch(command)[0]).to eq({ op: "AUTHENTICATE SECKEY:301:0.NA/FAKE.ADMIN", data: "seckey" })
            ""
          end
        }.should be_true
      end
    end

    describe "handle manipulation" do
      let(:fake_handle) { 'FAKE.PREFIX/FAKE.HANDLE' }
      let(:new_handle)  { 'FAKE.PREFIX/NEW.HANDLE'  }
      let(:bad_handle)  { 'FAKE.PREFIX/NEW.HANDLE'  }

      let(:record) {
        record = Handle::Record.new
        record.add(:URL, 'http://www.example.edu/fake-handle').index = 2
        record.add(:Email, 'handle@example.edu').index = 6
        record << Handle::Field::HSAdmin.new('0.NA/FAKE.ADMIN')
        record
      }
      let(:server) { double(Handle::Java::Native::HSAdapter) }
      subject { Handle::Command::Connection.new('0.NA/FAKE.ADMIN', 300, 'privkey', 'keypass') }

      it "#resolve_handle" do
        subject.should_receive(:`) { |command|
          expect(command).to match(/hdl-qresolver #{fake_handle}/)
          "Got Response:\n#{record.to_s}"
        }
        expect(subject.resolve_handle(fake_handle)).to eq(record)
      end

      it "#resolve_handle (not found)" do
        subject.should_receive(:`) { |command|
          expect(command).to match(/hdl-qresolver #{bad_handle}/)
          "Got Error:\nError(100): HANDLE NOT FOUND"
        }
        expect { subject.resolve_handle(bad_handle) }.to raise_error(Handle::NotFound)
      end

      it "#resolve_handle (other error)" do
        subject.should_receive(:`) { |command|
          expect(command).to match(/hdl-qresolver #{bad_handle}/)
          "Got Error:\nError(3): SERVER TOO BUSY"
        }
        expect { subject.resolve_handle(bad_handle) }.to raise_error(Handle::HandleError)
      end

      it "#create_record" do
        new_record = subject.create_record(new_handle)
        expect(new_record.connection).to eq(subject)
        expect(new_record.handle).to eq(new_handle)
      end

      it "#create_handle" do
        Handle::Command::Batch.any_instance.should_receive(:`) do |command|
          ops = parse_batch(command)
          expect(ops.length).to eq(2)
          expect(ops[1][:op]).to eq("CREATE #{new_handle}")
          expect(ops[1][:data]).to eq("2 URL 86400 1110 UTF8 http://www.example.edu/fake-handle\n6 EMAIL 86400 1110 UTF8 handle@example.edu\n100 HS_ADMIN 86400 1110 ADMIN 300:111111111111:0.NA/FAKE.ADMIN")
          "==>SUCCESS[7]: create:#{new_handle}"
        end
        expect(subject.create_handle(new_handle, record)).to be_true
      end

      it "#create_handle (handle already exists)" do
        Handle::Command::Batch.any_instance.should_receive(:`) do |command|
          ops = parse_batch(command)
          expect(ops.length).to eq(2)
          expect(ops[1][:op]).to eq("CREATE #{new_handle}")
          expect(ops[1][:data]).to eq("2 URL 86400 1110 UTF8 http://www.example.edu/fake-handle\n6 EMAIL 86400 1110 UTF8 handle@example.edu\n100 HS_ADMIN 86400 1110 ADMIN 300:111111111111:0.NA/FAKE.ADMIN")
          "==>FAILURE[7]: create:#{new_handle}: Error(101): HANDLE ALREADY EXISTS"
        end
        expect { subject.create_handle(new_handle, record) }.to raise_error(Handle::HandleError)
      end

      it "#add_handle_values" do
        Handle::Command::Batch.any_instance.should_receive(:`) do |command|
          ops = parse_batch(command)
          expect(ops.length).to eq(2)
          expect(ops[1][:op]).to eq("ADD #{new_handle}")
          expect(ops[1][:data]).to eq("2 URL 86400 1110 UTF8 http://www.example.edu/fake-handle\n6 EMAIL 86400 1110 UTF8 handle@example.edu\n100 HS_ADMIN 86400 1110 ADMIN 300:111111111111:0.NA/FAKE.ADMIN")
          "==>SUCCESS[7]: add values:#{new_handle}"
        end
        expect(subject.add_handle_values(new_handle, record)).to be_true
      end

      it "#update_handle_values" do
        Handle::Command::Batch.any_instance.should_receive(:`) do |command|
          ops = parse_batch(command)
          expect(ops.length).to eq(2)
          expect(ops[1][:op]).to eq("MODIFY #{new_handle}")
          expect(ops[1][:data]).to eq("2 URL 86400 1110 UTF8 http://www.example.edu/fake-handle\n6 EMAIL 86400 1110 UTF8 handle@example.edu\n100 HS_ADMIN 86400 1110 ADMIN 300:111111111111:0.NA/FAKE.ADMIN")
          "==>SUCCESS[7]: modify values:#{new_handle}"
        end
        expect(subject.update_handle_values(new_handle, record)).to be_true
      end

      it "#delete_handle_values" do
        Handle::Command::Batch.any_instance.should_receive(:`) do |command|
          ops = parse_batch(command)
          expect(ops.length).to eq(2)
          expect(ops[1][:op]).to eq("REMOVE 2,6,100:#{new_handle}")
          expect(ops[1][:data]).to be_empty
          "==>SUCCESS[4]: delete values:#{new_handle}"
        end
        expect(subject.delete_handle_values(new_handle, record)).to be_true
      end

      it "#delete_handle" do
        Handle::Command::Batch.any_instance.should_receive(:`) do |command|
          ops = parse_batch(command)
          expect(ops.length).to eq(2)
          expect(ops[1][:op]).to eq("DELETE #{new_handle}")
          expect(ops[1][:data]).to be_empty
          "==>SUCCESS[7]: delete:#{new_handle}"
        end
        expect(subject.delete_handle(new_handle)).to be_true
      end
    end
  end
end